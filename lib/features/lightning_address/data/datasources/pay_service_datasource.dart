import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

class PayServiceDatasource implements PayServicePort {
  static const _boxName = 'lightning_address';
  static const _addressKey = 'address';

  final Dio _dio;

  PayServiceDatasource({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: payServiceBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));

  @override
  Future<String> register({
    required String nym,
    required String ctDescriptor,
    required String npubHex,
    required String signatureHex,
    required int timestampSecs,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/register',
        data: {
          'nym': nym,
          'ct_descriptor': ctDescriptor,
          'npub': npubHex,
          'signature': signatureHex,
          'timestamp': timestampSecs,
        },
      );

      final data = response.data;
      if (data == null) throw PayServiceException('Invalid server response');

      if (data['status'] == 'ERROR') {
        throw PayServiceException(
            data['reason'] as String? ?? 'Unknown error');
      }

      final address = data['lightning_address'] as String;

      final box = await Hive.openBox<String>(_boxName);
      await box.put(_addressKey, address);

      return address;
    } on DioException catch (e) {
      throw PayServiceException(
        _extractDioErrorMessage(e),
      );
    }
  }

  @override
  Future<String?> getStoredAddress() async {
    final box = await Hive.openBox<String>(_boxName);
    return box.get(_addressKey);
  }

  @override
  Future<void> storeAddress(String address) async {
    final box = await Hive.openBox<String>(_boxName);
    await box.put(_addressKey, address);
  }

  @override
  Future<({String nym, bool active})?> lookupByNpub(String npubHex) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/register/lookup',
        queryParameters: {'npub': npubHex},
      );
      final data = response.data;
      if (data == null || data['status'] == 'ERROR') return null;
      return (nym: data['nym'] as String, active: data['active'] as bool);
    } on DioException catch (e) {
      // 404 = npub has no registration. Anything else (5xx, timeout,
      // connection-reset) is a transient failure the caller must distinguish
      // from "not registered" — otherwise one network blip silently kills
      // recovery on this device.
      if (e.response?.statusCode == 404) return null;
      throw PayServiceException(_extractDioErrorMessage(e));
    }
  }

  @override
  Future<void> deleteRegistration({
    required String npubHex,
    required String signatureHex,
    required int timestampSecs,
  }) async {
    try {
      final response = await _dio.delete<dynamic>(
        '/register',
        data: {
          'npub': npubHex,
          'signature': signatureHex,
          'timestamp': timestampSecs,
        },
      );

      if (response.data is Map && response.data['status'] == 'ERROR') {
        throw PayServiceException(
          response.data['reason'] as String? ?? 'Unknown error',
        );
      }

      final box = await Hive.openBox<String>(_boxName);
      await box.delete(_addressKey);
    } on DioException catch (e) {
      throw PayServiceException(
        _extractDioErrorMessage(e),
      );
    }
  }

  String _extractDioErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['reason'] != null) {
      return data['reason'] as String;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Server is not responding. Please try again.';
    }
    return 'Network error. Please check your connection.';
  }
}
