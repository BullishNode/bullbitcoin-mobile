import 'package:bb_mobile/features/lightning_address/domain/entities/lookup_result.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bb_mobile/features/lightning_address/domain/ports/pay_service_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
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
  Future<({String address, NymQuota quota})> register({
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
      final quota = _quotaFromJson(data['quota']);

      final box = await Hive.openBox<String>(_boxName);
      await box.put(_addressKey, address);

      return (address: address, quota: quota);
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
  Future<LookupResult?> lookupByNpub(String npubHex) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/register/lookup',
        queryParameters: {'npub': npubHex},
      );
      final data = response.data;
      if (data == null || data['status'] == 'ERROR') return null;
      final nym = data['nym'] as String;
      final active = data['active'] as bool;
      final quota = _quotaFromJson(data['quota']);
      return active
          ? ActiveLookupResult(nym: nym, quota: quota)
          : InactiveLookupResult(nym: nym, quota: quota);
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
  Future<NymQuota> deleteRegistration({
    required String npubHex,
    required String signatureHex,
    required int timestampSecs,
  }) async {
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/register',
        data: {
          'npub': npubHex,
          'signature': signatureHex,
          'timestamp': timestampSecs,
        },
      );

      final data = response.data;
      if (data != null && data['status'] == 'ERROR') {
        throw PayServiceException(
          data['reason'] as String? ?? 'Unknown error',
        );
      }

      final box = await Hive.openBox<String>(_boxName);
      await box.delete(_addressKey);

      // Server returns the post-delete quota; mobile uses it to drive the
      // dereg-warning copy without an extra `lookupByNpub` round trip.
      return _quotaFromJson(data?['quota']);
    } on DioException catch (e) {
      throw PayServiceException(
        _extractDioErrorMessage(e),
      );
    }
  }

  /// Parse the server's `quota: {used, cap, remaining}` block. `remaining`
  /// is recomputed locally — never trust a derived field over the wire.
  NymQuota _quotaFromJson(dynamic raw) {
    final m = raw is Map ? raw : const {};
    final used = (m['used'] as num?)?.toInt() ?? 0;
    final cap = (m['cap'] as num?)?.toInt() ?? 0;
    return NymQuota(used: used, cap: cap);
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
