import 'package:dio/dio.dart';

class BullnymException implements Exception {
  final String code;
  final String reason;
  final Map<String, dynamic>? details;
  final int? statusCode;

  const BullnymException({
    required this.code,
    required this.reason,
    this.details,
    this.statusCode,
  });

  factory BullnymException.fromResponse(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic> && data['status'] == 'ERROR') {
      return BullnymException(
        code: data['code'] as String? ?? 'UnknownError',
        reason: data['reason'] as String? ?? 'Unknown server error',
        details: data['details'] as Map<String, dynamic>?,
        statusCode: response.statusCode,
      );
    }
    return BullnymException(
      code: 'HttpError',
      reason: 'Unexpected server response',
      statusCode: response.statusCode,
    );
  }

  @override
  String toString() => 'BullnymException($code): $reason';
}

class BullnymNetworkException extends BullnymException {
  BullnymNetworkException(String reason)
    : super(code: 'NetworkError', reason: reason);
}

T requireJson<T>(Response<T> response) {
  final data = response.data;
  if (data == null) {
    throw BullnymException(
      code: 'EmptyResponse',
      reason: 'Server returned an empty response',
      statusCode: response.statusCode,
    );
  }
  return data;
}

void throwIfBullnymError(Response<dynamic> response) {
  final data = response.data;
  if (data is Map<String, dynamic> && data['status'] == 'ERROR') {
    throw BullnymException.fromResponse(response);
  }
}
