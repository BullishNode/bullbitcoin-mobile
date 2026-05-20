import 'dart:convert';

import 'package:bb_mobile/features/get_paid/btcpay/application/ports/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:dio/dio.dart';

class SamRockPairingDatasource implements SamRockPairingServicePort {
  final Dio _dio;

  SamRockPairingDatasource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) => status != null && status < 600,
            ),
          );

  @override
  Future<SamRockPairingResponse> submitSetup({
    required SamRockPairingRequest request,
    required Map<String, Object?> payload,
  }) async {
    final response = await _dio.post<String>(
      request.protocolUri.toString(),
      data: {'json': jsonEncode(payload)},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    final body = _decodeResponse(response.data);
    final statusCode = response.statusCode ?? 0;
    final isHttpSuccess = statusCode >= 200 && statusCode < 300;
    final message = _message(body);

    final success = body['Success'] ?? body['success'];
    return SamRockPairingResponse(
      success: isHttpSuccess && success is bool ? success : false,
      serverFailure: !isHttpSuccess,
      message: isHttpSuccess
          ? message
          : message ?? 'BTCPay SamRock server returned HTTP $statusCode',
      result: _mapResult(body['Result'] ?? body['result']),
    );
  }

  String? _message(Map<String, Object?> body) {
    return body['Message']?.toString() ??
        body['message']?.toString() ??
        body['Error']?.toString() ??
        body['error']?.toString();
  }

  Map<String, Object?> _decodeResponse(Object? data) {
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    if (data is String && data.trim().isNotEmpty) {
      final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return const {};
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return const {};
  }

  Map<String, Object?> _mapResult(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}
